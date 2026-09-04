import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/common/services/desktop_storage_service.dart';
import 'package:salvador_desktop/common/services/system_memory_service.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/config/inject/app_injector.dart';
import 'package:salvador_desktop/data/datasources/chat_agent_datasource.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';
import 'package:salvador_desktop/data/datasources/workspace_datasource.dart';
import 'package:salvador_desktop/data/repositories/chat_repository_impl.dart';
import 'package:salvador_desktop/data/repositories/ollama_repository_impl.dart';
import 'package:salvador_desktop/data/repositories/workspace_repository_impl.dart';
import 'package:salvador_desktop/domain/entities/desktop_preferences_entity.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';
import 'package:salvador_desktop/domain/interfaces/ollama_repository.dart';
import 'package:salvador_desktop/presentation/desktop/chat/view_model/chat_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/chat/view_model/chat_state.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_assistant_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_assistant_state.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/file_explorer_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/settings_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/settings_state.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_state.dart';
import 'package:salvador_desktop/presentation/desktop/view/desktop_view.dart';

import 'presentation/git/fakes/fake_git_assistant_repository.dart';
import 'presentation/git/fakes/fake_git_repository.dart';

/// Suíte de integração: registra Cubits reais no AppInjector, faking só a
/// borda de rede (OllamaClient) e a borda de disco (DesktopStorageService),
/// exatamente como o antigo `buildController` fakeava só o `OllamaClient`
/// por trás do `DesktopController`. Isso continua exercitando o fluxo real
/// (WorkspaceCubit -> ChatCubit/FileExplorerCubit via MultiBlocListener) em
/// vez de mockar cada Cubit isoladamente.
void main() {
  final tempDirs = <Directory>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = null;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await AppInjector.inject.reset();
    for (final dir in tempDirs) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    tempDirs.clear();
  });

  Future<_Harness> buildHarness(
    WidgetTester tester, {
    List<OllamaRunningModel> running = const [],
    DesktopPreferencesEntity Function(Directory root)? initialPreferences,
  }) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('salvador_shell_test_'),
    );
    tempDirs.add(root!);
    final fake = _FakeClient(
      model: 'llama3.2:3b',
      baseUrl: Uri.parse('http://127.0.0.1:11434'),
    )..running = List.of(running);

    OllamaClient clientFactory({
      required String model,
      required Uri baseUrl,
      required InferenceOptions options,
    }) => fake;

    await AppInjector.inject.reset();

    final storage = _NoIoStore(initial: initialPreferences?.call(root));
    final memoryReader = SystemMemoryReader(
      runner: (_, _) async => ProcessResult(1, 0, '', ''),
    );
    final OllamaRepository ollamaRepository = OllamaRepositoryImpl(
      OllamaRemoteDataSource(clientFactory: clientFactory),
    );
    final chatRepository = ChatRepositoryImpl(
      ChatAgentDataSource(clientFactory: clientFactory),
    );
    final workspaceRepository = WorkspaceRepositoryImpl(WorkspaceDataSource());

    final workspaceCubit = WorkspaceCubit(
      ollamaRepository,
      storage,
      initialRoot: root,
      memoryReader: memoryReader,
    );
    final chatCubit = ChatCubit(
      chatRepository,
      clock: () => DateTime(2026, 8, 28, 12),
    );
    final fileExplorerCubit = FileExplorerCubit(workspaceRepository);
    final gitRepository = FakeGitRepository();
    final gitCubit = GitCubit(gitRepository);
    final gitAssistantRepository = FakeGitAssistantRepository();
    final gitAssistantCubit = GitAssistantCubit(gitAssistantRepository);

    AppInjector.inject
      ..registerFactory<WorkspaceCubit>(() => workspaceCubit)
      ..registerFactory<ChatCubit>(() => chatCubit)
      ..registerFactory<FileExplorerCubit>(() => fileExplorerCubit)
      ..registerFactory<GitCubit>(() => gitCubit)
      ..registerFactory<GitAssistantCubit>(() => gitAssistantCubit)
      ..registerFactoryParam<SettingsCubit, SettingsEditing, void>(
        (initial, _) => SettingsCubit(ollamaRepository, initial: initial),
      );

    return _Harness(
      root: root,
      fake: fake,
      storage: storage,
      workspaceCubit: workspaceCubit,
      chatCubit: chatCubit,
      fileExplorerCubit: fileExplorerCubit,
      gitRepository: gitRepository,
      gitCubit: gitCubit,
      gitAssistantRepository: gitAssistantRepository,
      gitAssistantCubit: gitAssistantCubit,
    );
  }

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(const DesktopView());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'top bar reflete estados do modelo e aciona start/stop/nova sessão',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final harness = await buildHarness(tester);
      await pumpShell(tester);

      expect(find.byKey(const Key('workspace-top-bar')), findsOneWidget);
      expect(find.text('Iniciar modelo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('start-stop-button')));
      await tester.pumpAndSettle();
      expect(
        (harness.workspaceCubit.state as WorkspaceReady).modelState,
        WorkspaceModelState.running,
      );
      expect(harness.fake.loadedModels, ['llama3.2:3b']);
      expect(find.text('Encerrar modelo'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('composer-field')), 'oi');
      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pumpAndSettle();
      expect((harness.chatCubit.state as ChatIdle).messages, isNotEmpty);

      final newSessionButton = tester.widget<TextButton>(
        find.byKey(const Key('new-session-button')),
      );
      expect(newSessionButton.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('new-session-button')));
      await tester.pumpAndSettle();
      expect((harness.chatCubit.state as ChatIdle).messages, isEmpty);

      await tester.tap(find.byKey(const Key('start-stop-button')));
      await tester.pumpAndSettle();
      expect(
        (harness.workspaceCubit.state as WorkspaceReady).modelState,
        WorkspaceModelState.stopped,
      );
      expect(find.text('Iniciar modelo'), findsOneWidget);
    },
  );

  testWidgets('menu de pasta lista recentes e troca a pasta ativa', (
    tester,
  ) async {
    final harness = await buildHarness(tester);
    final other = await tester.runAsync(
      () => Directory('${harness.root.path}/outro-projeto').create(),
    );
    harness.storage.seed(
      DesktopPreferencesEntity(
        activeRoot: harness.root.path,
        recentRoots: [harness.root.path, other!.path],
      ),
    );
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('folder-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Pasta do projeto'), findsOneWidget);
    expect(find.text(other.path), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(find.text(other.path));
    await tester.pumpAndSettle();
    expect(
      (harness.workspaceCubit.state as WorkspaceReady).root!.path,
      other.path,
    );
  });

  testWidgets('menu de modelos lista status e seleciona outro modelo', (
    tester,
  ) async {
    final harness = await buildHarness(tester);
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('model-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-item-gemma2:2b')), findsOneWidget);
    expect(find.text('PARADO'), findsNWidgets(2));
    expect(find.text('contexto: 4096 tokens'), findsOneWidget);

    await tester.tap(find.byKey(const Key('model-item-gemma2:2b')));
    await tester.pumpAndSettle();
    final state = harness.workspaceCubit.state as WorkspaceReady;
    expect(state.selectedModel, 'gemma2:2b');
    expect(state.modelState, WorkspaceModelState.stopped);
    expect(harness.fake.loadedModels, isEmpty);
  });

  testWidgets('enviar mensagem inicia modelo parado e envia', (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await buildHarness(tester);
    await pumpShell(tester);
    expect(
      (harness.workspaceCubit.state as WorkspaceReady).modelState,
      WorkspaceModelState.stopped,
    );
    expect(find.text('Iniciar modelo'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'revise o projeto',
    );
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();

    final state = harness.workspaceCubit.state as WorkspaceReady;
    expect(state.modelState, WorkspaceModelState.running);
    expect(harness.fake.loadedModels, ['llama3.2:3b']);
    expect((harness.chatCubit.state as ChatIdle).messages, hasLength(2));
  });

  testWidgets('modal testa servidor, mantem edicao apos falha e salva', (
    tester,
  ) async {
    final harness = await buildHarness(tester);
    await pumpShell(tester);

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

    harness.fake.failConnection = true;
    await tester.tap(find.byKey(const Key('test-host-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Falha no teste'), findsOneWidget);
    expect(find.byKey(const Key('settings-dialog')), findsOneWidget);

    harness.fake.failConnection = false;
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
    final state = harness.workspaceCubit.state as WorkspaceReady;
    expect(state.inference.contextLength, 2048);
    expect(state.permissions.allowEdit, isFalse);
  });

  testWidgets('cancelar modal nao muta preferencias', (tester) async {
    final harness = await buildHarness(tester);
    await pumpShell(tester);
    final previousHost = (harness.workspaceCubit.state as WorkspaceReady).host;

    await tester.tap(find.byKey(const Key('open-settings-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings-host-field')),
      'http://192.168.1.99:11434',
    );
    await tester.tap(find.byKey(const Key('settings-cancel-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-dialog')), findsNothing);
    expect((harness.workspaceCubit.state as WorkspaceReady).host, previousHost);
  });

  testWidgets('painel de atividade alterna com o rail e lista sessoes', (
    tester,
  ) async {
    final harness = await buildHarness(
      tester,
      running: const [
        OllamaRunningModel(name: 'llama3.2:3b', isInstalled: true),
      ],
      initialPreferences: (root) => DesktopPreferencesEntity(
        sessions: [
          PersistedSessionSummaryEntity(
            title: 'Sessao antiga',
            startedAt: DateTime(2026, 8, 27),
            actionCount: 4,
          ),
        ],
      ),
    );
    await pumpShell(tester);

    expect(find.byKey(const Key('workspace-rail')), findsOneWidget);
    expect(find.byKey(const Key('activity-panel')), findsNothing);

    await tester.tap(find.byKey(const Key('rail-sessions-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-panel')), findsOneWidget);
    expect(
      find.text('As leituras, edições e comandos aparecerão aqui.'),
      findsOneWidget,
    );
    expect(find.text('Sessao antiga'), findsOneWidget);
    expect(find.textContaining('4 ações'), findsOneWidget);

    harness.fake.respondWithToolCall = true;
    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'grave um arquivo',
    );
    // write_file executa I/O real (ToolRegistry): precisa do event loop real,
    // nao apenas do tempo falso do pumpAndSettle - mesmo padrao de tapPreview.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('send-button')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();

    expect(find.text('Gravação'), findsOneWidget);
    expect((harness.chatCubit.state as ChatIdle).activities, hasLength(1));

    await tester.tap(find.byKey(const Key('collapse-panel-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-panel')), findsNothing);
    expect(find.byKey(const Key('workspace-rail')), findsOneWidget);
  });

  testWidgets('sessao atual aparece no painel durante a conversa', (
    tester,
  ) async {
    final harness = await buildHarness(
      tester,
      running: const [
        OllamaRunningModel(name: 'llama3.2:3b', isInstalled: true),
      ],
    );
    await pumpShell(tester);
    expect(
      (harness.workspaceCubit.state as WorkspaceReady).modelState,
      WorkspaceModelState.running,
    );

    await tester.tap(find.byKey(const Key('rail-sessions-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'revise o projeto',
    );
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();

    expect((harness.chatCubit.state as ChatIdle).messages, hasLength(2));
    expect(find.text('revise o projeto'), findsNWidgets(2));
    expect(find.textContaining('0 ações'), findsOneWidget);
  });

  testWidgets('top bar degrada sem overflow em janela estreita', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await buildHarness(tester);
    await pumpShell(tester);

    expect(find.byKey(const Key('start-stop-button')), findsOneWidget);
    expect(find.byKey(const Key('open-settings-button')), findsOneWidget);
    expect(find.byKey(const Key('new-session-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('title bar customizada aparece somente no macOS', (tester) async {
    await buildHarness(tester);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpShell(tester);
    expect(find.byKey(const Key('mac-title-bar')), findsNothing);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const DesktopView());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mac-title-bar')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('arvore expande, filtra e abre preview com mencao', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await buildHarness(
      tester,
      initialPreferences: (root) =>
          DesktopPreferencesEntity(activeRoot: root.path),
    );
    await tester.runAsync(() async {
      await Directory('${harness.root.path}/src').create();
      await File(
        '${harness.root.path}/src/main.dart',
      ).writeAsString('void main() {\n  return;\n}');
      await File('${harness.root.path}/README.md').writeAsString('# leia-me');
      await File('${harness.root.path}/imagem.bin').writeAsBytes([0, 1, 2]);
    });
    await pumpShell(tester);

    expect(find.byKey(const Key('files-rail')), findsOneWidget);
    await tester.tap(find.byKey(const Key('right-rail-files-button')));
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
    await tester.tap(find.byKey(const Key('right-rail-files-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tree-entry-README.md')),
      findsOneWidget,
      reason: 'filtro deve sobreviver ao recolher/reabrir',
    );

    await tester.enterText(find.byKey(const Key('file-filter-field')), '');
    await tester.pumpAndSettle();
    await tapPreview(tester, find.byKey(const Key('tree-entry-src/main.dart')));

    expect(find.byKey(const Key('file-preview-dialog')), findsOneWidget);
    expect(find.byKey(const Key('preview-pane')), findsOneWidget);
    expect(find.text('src/main.dart'), findsOneWidget);
    expect(find.textContaining('linhas'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mention-preview-button')));
    await tester.pumpAndSettle();
    final composer = tester.widget<TextField>(
      find.byKey(const Key('composer-field')),
    );
    expect(composer.controller!.text, '@src/main.dart ');
    expect(find.byKey(const Key('file-preview-dialog')), findsNothing);

    await tapPreview(tester, find.byKey(const Key('tree-entry-imagem.bin')));
    expect(find.byKey(const Key('file-preview-error-dialog')), findsOneWidget);
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
    await buildHarness(tester);
    await pumpShell(tester);

    expect(find.byKey(const Key('workspace-rail')), findsOneWidget);
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
      await buildHarness(tester);
      await pumpShell(tester);

      await tester.tap(find.byKey(const Key('rail-sessions-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('right-rail-files-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('activity-panel')), findsOneWidget);
      expect(find.byKey(const Key('files-panel')), findsOneWidget);
      expect(find.byKey(const Key('composer-field')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rail alterna para Git e volta ao Chat preservando estado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await buildHarness(tester);
    await pumpShell(tester);

    expect(find.byKey(const Key('chat-navigation-button')), findsOneWidget);
    expect(find.byKey(const Key('git-navigation-button')), findsOneWidget);
    expect(find.byKey(const Key('git-workspace')), findsNothing);
    expect(find.byKey(const Key('composer-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'mensagem antes do git',
    );
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();
    expect((harness.chatCubit.state as ChatIdle).messages, hasLength(2));

    await tester.tap(find.byKey(const Key('rail-sessions-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('git-navigation-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('git-workspace')), findsOneWidget);
    expect(find.byKey(const Key('composer-field')), findsNothing);

    await tester.tap(find.byKey(const Key('chat-navigation-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('git-workspace')), findsNothing);
    expect(find.byKey(const Key('composer-field')), findsOneWidget);
    expect((harness.chatCubit.state as ChatIdle).messages, hasLength(2));
    // A mensagem aparece na lista e como titulo da sessao no painel.
    expect(find.text('mensagem antes do git'), findsNWidgets(2));
    expect(
      find.byKey(const Key('activity-panel')),
      findsOneWidget,
      reason: 'painel lateral deve continuar expandido ao voltar ao Chat',
    );
  });

  testWidgets('modo Git sem projeto mostra estado vazio', (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await buildHarness(tester);
    await pumpShell(tester);
    expect((harness.workspaceCubit.state as WorkspaceReady).root, isNull);

    await tester.tap(find.byKey(const Key('git-navigation-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('git-workspace')), findsOneWidget);
    expect(
      find.text('Selecione um projeto para ver o status Git.'),
      findsOneWidget,
    );
  });

  testWidgets('modo Git mostra pasta sem repositorio e fora da raiz', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await buildHarness(
      tester,
      initialPreferences: (root) =>
          DesktopPreferencesEntity(activeRoot: root.path),
    );
    harness.gitRepository.nextResult = Result.ok(
      const GitSnapshot(
        repository: GitRepositoryState(kind: GitRepositoryKind.notRepository),
      ),
    );
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('git-navigation-button')));
    await tester.pumpAndSettle();
    expect(find.text('Esta pasta não é um repositório Git.'), findsOneWidget);

    harness.gitRepository.nextResult = const Result.ok(
      GitSnapshot(
        repository: GitRepositoryState(
          kind: GitRepositoryKind.repositoryOutsideRoot,
          topLevel: '/outro/repositorio',
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('git-refresh-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('/outro/repositorio'), findsOneWidget);
  });

  testWidgets('modo Git mostra carregando e depois o snapshot valido', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await buildHarness(
      tester,
      initialPreferences: (root) =>
          DesktopPreferencesEntity(activeRoot: root.path),
    );
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('git-navigation-button')));
    // O spinner de carregamento anima indefinidamente: pump manual em vez de
    // pumpAndSettle, que travaria esperando o fim da animacao.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Carregando repositório...'), findsOneWidget);

    harness.gitRepository.completeFirst(
      Result.ok(
        GitSnapshot(
          repository: GitRepositoryState(
            kind: GitRepositoryKind.valid,
            topLevel: harness.root.path,
            branch: 'main',
            headOid: '6b8dc2efa9f5ff3a00f6262229969f841cefa6fc',
            isDetachedHead: false,
          ),
          upstream: 'origin/main',
          ahead: 3,
          behind: 1,
          localBranches: const [
            GitRef(name: 'refs/heads/main', hash: 'h'),
            GitRef(name: 'refs/heads/feature', hash: 'h'),
          ],
          tags: const [GitRef(name: 'refs/tags/v1.0.0', hash: 'h')],
          commits: [
            GitCommit(
              hash: 'a',
              shortHash: 'a',
              subject: 's',
              authorName: 't',
              authorEmail: 't@t.co',
              authorDate: DateTime(2026, 8, 29),
            ),
          ],
          worktree: const [
            GitWorktreeEntry(path: 'a.txt', status: GitWorktreeStatus.unstaged),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('main'), findsWidgets);
    // ahead=3 e unico; behind=1 e repetido nas contagens dos grupos.
    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('sujo'), findsOneWidget);
    expect(find.byKey(const Key('git-refresh-button')), findsOneWidget);
  });

  testWidgets('modo Git mostra erro apresentavel do repositorio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await buildHarness(
      tester,
      initialPreferences: (root) =>
          DesktopPreferencesEntity(activeRoot: root.path),
    );
    harness.gitRepository.nextResult = const Result.error(
      GitFailureException('repositorio corrompido'),
    );
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('git-navigation-button')));
    await tester.pumpAndSettle();

    expect(find.text('repositorio corrompido'), findsOneWidget);
  });

  testWidgets('assistente Git mantem conversa independente do chat', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await buildHarness(
      tester,
      initialPreferences: (root) =>
          DesktopPreferencesEntity(activeRoot: root.path),
    );
    harness.gitRepository.nextResult = Result.ok(
      GitSnapshot(
        repository: const GitRepositoryState(
          kind: GitRepositoryKind.valid,
          topLevel: '/repo/raiz',
          branch: 'main',
          headOid: '6b8dc2efa9f5ff3a00f6262229969f841cefa6fc',
        ),
      ),
    );
    await pumpShell(tester);

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'mensagem do chat',
    );
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();
    expect((harness.chatCubit.state as ChatIdle).messages, hasLength(2));

    await tester.tap(find.byKey(const Key('git-navigation-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('git-ask-assistant-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('git-assistant-drawer')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('git-assistant-field')),
      'explique a branch',
    );
    await tester.tap(find.byKey(const Key('git-assistant-send')));
    await tester.pumpAndSettle();

    final assistantState = harness.gitAssistantCubit.state as GitAssistantIdle;
    expect(assistantState.messages, hasLength(2));
    expect(assistantState.messages.first.content, 'explique a branch');
    expect(
      find.text('explique a branch'),
      findsOneWidget,
      reason: 'a mensagem aparece no drawer, nao no chat',
    );

    await tester.tap(find.byKey(const Key('chat-navigation-button')));
    await tester.pumpAndSettle();
    expect((harness.chatCubit.state as ChatIdle).messages, hasLength(2));
    expect(find.text('mensagem do chat'), findsWidgets);
    expect(
      find.text('explique a branch'),
      findsNothing,
      reason: 'a conversa Git nao aparece no chat principal',
    );
  });
}

Future<void> tapPreview(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  await tester.pumpAndSettle();
}

class _Harness {
  _Harness({
    required this.root,
    required this.fake,
    required this.storage,
    required this.workspaceCubit,
    required this.chatCubit,
    required this.fileExplorerCubit,
    required this.gitRepository,
    required this.gitCubit,
    required this.gitAssistantRepository,
    required this.gitAssistantCubit,
  });

  final Directory root;
  final _FakeClient fake;
  final _NoIoStore storage;
  final WorkspaceCubit workspaceCubit;
  final ChatCubit chatCubit;
  final FileExplorerCubit fileExplorerCubit;
  final FakeGitRepository gitRepository;
  final GitCubit gitCubit;
  final FakeGitAssistantRepository gitAssistantRepository;
  final GitAssistantCubit gitAssistantCubit;
}

class _NoIoStore extends DesktopStorageService {
  _NoIoStore({DesktopPreferencesEntity? initial})
    : _state = initial ?? const DesktopPreferencesEntity(),
      super(file: File('/tmp/salvador_shell_test_noop.json'));

  DesktopPreferencesEntity _state;
  DesktopPreferencesEntity? lastSaved;

  void seed(DesktopPreferencesEntity state) => _state = state;

  @override
  Future<DesktopPreferencesEntity> load() async => _state;

  @override
  Future<void> save(DesktopPreferencesEntity state) async {
    _state = state;
    lastSaved = state;
  }
}

class _FakeClient extends OllamaClient {
  _FakeClient({required super.model, required super.baseUrl});

  bool failConnection = false;
  List<OllamaRunningModel> running = const [];
  final List<String> loadedModels = [];
  final List<String> unloadedModels = [];
  bool respondWithToolCall = false;
  int _chatCallCount = 0;

  @override
  Future<AgentMessage> chat({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async {
    _chatCallCount++;
    if (respondWithToolCall && _chatCallCount == 1) {
      return AgentMessage(
        role: 'assistant',
        toolCalls: [
          ToolCall(
            name: 'write_file',
            arguments: {'path': 'a.txt', 'content': 'oi'},
          ),
        ],
      );
    }
    return AgentMessage(role: 'assistant', content: 'ok');
  }

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
