import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/src/desktop/desktop_controller.dart';
import 'package:salvador_desktop/common/services/desktop_storage_service.dart';
import 'package:salvador_desktop/domain/entities/desktop_preferences_entity.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';
import 'package:salvador_desktop/src/desktop/salvador_desktop_app.dart';
import 'package:salvador_desktop/common/services/system_memory_service.dart';

void main() {
  final tempDirs = <Directory>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = null;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final dir in tempDirs) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    tempDirs.clear();
  });

  Future<(DesktopController, _FakeClient)> buildController(
    WidgetTester tester, {
    List<OllamaRunningModel> running = const [],
  }) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('salvador_shell_test_'),
    );
    tempDirs.add(root!);
    final fake = _FakeClient(
      model: 'llama3.2:3b',
      baseUrl: Uri.parse('http://127.0.0.1:11434'),
    )..running = List.of(running);
    final controller = await tester.runAsync(() async {
      final created = DesktopController(
        initialRoot: root,
        store: _NoIoStore(),
        clientFactory: ({required model, required baseUrl, required options}) =>
            fake,
        memoryReader: SystemMemoryReader(
          runner: (_, _) async => ProcessResult(1, 0, '', ''),
        ),
        clock: () => DateTime(2026, 8, 28, 12),
      );
      await created.initialize();
      return created;
    });
    return (controller!, fake);
  }

  Future<void> pumpShell(
    WidgetTester tester,
    DesktopController controller,
  ) async {
    await tester.pumpWidget(SalvadorDesktopApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'top bar reflete estados do modelo e aciona start/stop/nova sessão',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final (controller, fake) = await buildController(tester);
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      expect(find.byKey(const Key('workspace-top-bar')), findsOneWidget);
      expect(find.text('Iniciar modelo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('start-stop-button')));
      await tester.pumpAndSettle();
      expect(controller.modelState, ModelRunState.running);
      expect(fake.loadedModels, ['llama3.2:3b']);
      expect(find.text('Encerrar modelo'), findsOneWidget);

      controller.modelState = ModelRunState.starting;
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('Aguarde…'), findsOneWidget);
      final busyButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('start-stop-button')),
      );
      expect(busyButton.onPressed, isNull);

      controller.modelState = ModelRunState.running;
      controller.messages.add(
        const ChatEntry(role: ChatRole.user, content: 'oi'),
      );
      controller.notifyListeners();
      await tester.pump();
      final newSessionButton = tester.widget<TextButton>(
        find.byKey(const Key('new-session-button')),
      );
      expect(newSessionButton.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('new-session-button')));
      await tester.pumpAndSettle();
      expect(controller.messages, isEmpty);

      await tester.tap(find.byKey(const Key('start-stop-button')));
      await tester.pumpAndSettle();
      expect(controller.modelState, ModelRunState.stopped);
      expect(find.text('Iniciar modelo'), findsOneWidget);
    },
  );

  testWidgets('menu de pasta lista recentes e troca a pasta ativa', (
    tester,
  ) async {
    final (controller, _) = await buildController(tester);
    addTearDown(controller.dispose);
    final other = await tester.runAsync(
      () => Directory('${controller.root.path}/outro-projeto').create(),
    );
    controller.recentRoots = [controller.root.path, other!.path];
    controller.notifyListeners();
    await pumpShell(tester, controller);

    await tester.tap(find.byKey(const Key('folder-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Pasta do projeto'), findsOneWidget);
    expect(find.text(other.path), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(find.text(other.path));
    await tester.pumpAndSettle();
    expect(controller.root.path, other.path);
  });

  testWidgets('menu de modelos lista status e seleciona outro modelo', (
    tester,
  ) async {
    final (controller, fake) = await buildController(tester);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byKey(const Key('model-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-item-gemma2:2b')), findsOneWidget);
    expect(find.text('PARADO'), findsNWidgets(2));
    expect(find.text('contexto: 4096 tokens'), findsOneWidget);

    await tester.tap(find.byKey(const Key('model-item-gemma2:2b')));
    await tester.pumpAndSettle();
    expect(controller.selectedModel, 'gemma2:2b');
    expect(controller.modelState, ModelRunState.running);
    expect(fake.loadedModels, ['gemma2:2b']);
  });

  testWidgets('modal testa servidor, mantem edicao apos falha e salva', (
    tester,
  ) async {
    final (controller, fake) = await buildController(tester);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byKey(const Key('open-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
    expect(find.text('Acesso à rede'), findsOneWidget);
    final networkSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('settings-network-access')),
    );
    expect(networkSwitch.onChanged, isNull);
    expect(networkSwitch.value, isFalse);
    expect(find.textContaining('Desabilitado: run_command'), findsOneWidget);

    fake.failConnection = true;
    await tester.tap(find.byKey(const Key('test-host-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Falha no teste'), findsOneWidget);
    expect(find.byKey(const Key('settings-dialog')), findsOneWidget);

    fake.failConnection = false;
    await tester.tap(find.byKey(const Key('test-host-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Servidor ok'), findsOneWidget);
    expect(find.textContaining('modelo(s) instalado(s)'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('settings-context-field')),
      '2048',
    );
    await tester.ensureVisible(find.byKey(const Key('settings-allow-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-allow-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-save-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-dialog')), findsNothing);
    expect(controller.contextLength, 2048);
    expect(controller.allowEdit, isFalse);
  });

  testWidgets('cancelar modal nao muta preferencias', (tester) async {
    final (controller, _) = await buildController(tester);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    final previousHost = controller.host;

    await tester.tap(find.byKey(const Key('open-settings-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings-host-field')),
      'http://192.168.1.99:11434',
    );
    await tester.tap(find.byKey(const Key('settings-cancel-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-dialog')), findsNothing);
    expect(controller.host, previousHost);
  });

  testWidgets('painel de atividade alterna com o rail e lista sessoes', (
    tester,
  ) async {
    final (controller, _) = await buildController(tester);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('activity-rail')), findsOneWidget);
    expect(find.byKey(const Key('activity-panel')), findsNothing);

    await tester.tap(find.byKey(const Key('expand-panel-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-panel')), findsOneWidget);
    expect(
      find.text('As leituras, edições e comandos aparecerão aqui.'),
      findsOneWidget,
    );

    controller.activities.insert(
      0,
      ToolActivity(
        ToolCall(name: 'write_file', arguments: {'path': 'a.txt'}),
        'OK: arquivo gravado: a.txt (3 caracteres)',
        happenedAt: DateTime(2026, 8, 28, 11, 59),
      ),
    );
    controller.sessions = [
      PersistedSessionSummaryEntity(
        title: 'Sessao antiga',
        startedAt: DateTime(2026, 8, 27),
        actionCount: 4,
      ),
    ];
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Gravação'), findsOneWidget);
    expect(
      find.text('OK: arquivo gravado: a.txt (3 caracteres)'),
      findsOneWidget,
    );
    expect(find.text('Sessao antiga'), findsOneWidget);
    expect(find.textContaining('4 ações'), findsOneWidget);

    await tester.tap(find.byKey(const Key('collapse-panel-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-panel')), findsNothing);
    expect(find.byKey(const Key('activity-rail')), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('sessao atual aparece no painel durante a conversa', (
    tester,
  ) async {
    final (controller, _) = await buildController(
      tester,
      running: const [
        OllamaRunningModel(name: 'llama3.2:3b', isInstalled: true),
      ],
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    expect(controller.modelState, ModelRunState.running);

    await tester.tap(find.byKey(const Key('expand-panel-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'revise o projeto',
    );
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();

    expect(controller.messages, hasLength(2));
    expect(find.text('revise o projeto'), findsNWidgets(2));
    expect(find.textContaining('0 ações'), findsOneWidget);
  });

  testWidgets('top bar degrada sem overflow em janela estreita', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final (controller, _) = await buildController(tester);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('start-stop-button')), findsOneWidget);
    expect(find.byKey(const Key('open-settings-button')), findsOneWidget);
    expect(find.byKey(const Key('new-session-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('title bar customizada aparece somente no macOS', (tester) async {
    final (controller, _) = await buildController(tester);
    addTearDown(controller.dispose);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpShell(tester, controller);
    expect(find.byKey(const Key('mac-title-bar')), findsNothing);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(SalvadorDesktopApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mac-title-bar')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('arvore expande, filtra e abre preview com mencao', (
    tester,
  ) async {
    final (controller, _) = await buildController(tester);
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      await Directory('${controller.root.path}/src').create();
      await File(
        '${controller.root.path}/src/main.dart',
      ).writeAsString('void main() {\n  return;\n}');
      await File(
        '${controller.root.path}/README.md',
      ).writeAsString('# leia-me');
      await File('${controller.root.path}/imagem.bin').writeAsBytes([0, 1, 2]);
    });
    controller.refreshTree();
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('files-rail')), findsOneWidget);
    await tester.tap(find.byKey(const Key('expand-files-panel-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('files-panel')), findsOneWidget);
    expect(find.byKey(const Key('tree-entry-src')), findsOneWidget);
    expect(find.byKey(const Key('tree-entry-src/main.dart')), findsNothing);

    await tester.tap(find.byKey(const Key('tree-entry-src')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tree-entry-src/main.dart')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('file-filter-field')),
      'readme',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tree-entry-src')), findsNothing);
    expect(find.byKey(const Key('tree-entry-README.md')), findsOneWidget);

    await tester.tap(find.byKey(const Key('collapse-files-panel-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expand-files-panel-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tree-entry-README.md')),
      findsOneWidget,
      reason: 'filtro deve sobreviver ao recolher/reabrir',
    );

    await tester.enterText(find.byKey(const Key('file-filter-field')), '');
    await tester.pumpAndSettle();
    await tapPreview(tester, find.byKey(const Key('tree-entry-src/main.dart')));

    expect(find.byKey(const Key('preview-pane')), findsOneWidget);
    expect(find.text('src/main.dart'), findsOneWidget);
    expect(find.textContaining('linhas'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mention-preview-button')));
    await tester.pumpAndSettle();
    final composer = tester.widget<TextField>(
      find.byKey(const Key('composer-field')),
    );
    expect(composer.controller!.text, '@src/main.dart ');

    await tester.tap(find.byKey(const Key('close-preview-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-pane')), findsNothing);

    await tapPreview(tester, find.byKey(const Key('tree-entry-imagem.bin')));
    expect(find.byKey(const Key('preview-error-pane')), findsOneWidget);
    expect(find.textContaining('binario'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-preview-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-error-pane')), findsNothing);
  });

  testWidgets('janela estreita com os dois rails nao gera overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(560, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final (controller, _) = await buildController(tester);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('activity-rail')), findsOneWidget);
    expect(find.byKey(const Key('files-rail')), findsOneWidget);
    expect(find.byKey(const Key('composer-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'janela compacta com os dois paineis expandidos nao gera overflow',
    (tester) async {
      tester.view.physicalSize = const Size(980, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final (controller, _) = await buildController(tester);
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      await tester.tap(find.byKey(const Key('expand-panel-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expand-files-panel-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('activity-panel')), findsOneWidget);
      expect(find.byKey(const Key('files-panel')), findsOneWidget);
      expect(find.byKey(const Key('composer-field')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> tapPreview(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  await tester.pumpAndSettle();
}

class _NoIoStore extends DesktopStorageService {
  _NoIoStore() : super(file: File('/tmp/salvador_shell_test_noop.json'));

  DesktopPreferencesEntity? lastSaved;

  @override
  Future<DesktopPreferencesEntity> load() async => const DesktopPreferencesEntity();

  @override
  Future<void> save(DesktopPreferencesEntity state) async {
    lastSaved = state;
  }
}

class _FakeClient extends OllamaClient {
  _FakeClient({required super.model, required super.baseUrl});

  bool failConnection = false;
  List<OllamaRunningModel> running = const [];
  final List<String> loadedModels = [];
  final List<String> unloadedModels = [];

  @override
  Future<AgentMessage> chat({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async => AgentMessage(role: 'assistant', content: 'ok');

  @override
  Future<void> testConnection() async {
    if (failConnection) throw const OllamaException('falha simulada');
  }

  @override
  Future<List<OllamaModelInfo>> listModels() async => const [
    OllamaModelInfo(name: 'llama3.2:3b', sizeBytes: 2019393189),
    OllamaModelInfo(name: 'gemma2:2b', sizeBytes: 1600000000),
  ];

  @override
  Future<List<OllamaRunningModel>> listRunningModels({
    List<OllamaModelInfo>? installed,
  }) async => running;

  @override
  Future<int?> showModel(String name) async => 4096;

  @override
  Future<void> loadModel(
    String name, {
    Duration keepAlive = const Duration(minutes: 5),
  }) async {
    loadedModels.add(name);
    running = [...running, OllamaRunningModel(name: name, isInstalled: true)];
  }

  @override
  Future<void> unloadModel(String name) async {
    unloadedModels.add(name);
    running = [
      for (final model in running)
        if (model.name != name) model,
    ];
  }
}
