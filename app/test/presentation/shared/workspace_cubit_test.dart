import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_state.dart';

import 'fakes/fake_desktop_storage_service.dart';
import 'fakes/fake_ollama_repository.dart';

void main() {
  late FakeOllamaRepository fakeOllama;
  late FakeDesktopStorageService fakeStorage;
  late Directory root;
  late Directory otherRoot;

  setUp(() async {
    fakeOllama = FakeOllamaRepository()
      ..models = const [OllamaModelInfo(name: 'llama3.2:3b')];
    fakeStorage = FakeDesktopStorageService();
    root = await Directory.systemTemp.createTemp('salvador_workspace_test_');
    otherRoot = await Directory.systemTemp.createTemp(
      'salvador_workspace_test_2_',
    );
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
    if (otherRoot.existsSync()) await otherRoot.delete(recursive: true);
  });

  WorkspaceCubit buildCubit() =>
      WorkspaceCubit(fakeOllama, fakeStorage, initialRoot: root);

  group('WorkspaceCubit.initialize', () {
    blocTest<WorkspaceCubit, WorkspaceState>(
      'initialize_whenModelsInstalled_emitsReadyWithModels',
      build: buildCubit,
      act: (cubit) => cubit.initialize(),
      expect: () => [
        isA<WorkspaceReady>().having((s) => s.connecting, 'connecting', true),
        isA<WorkspaceReady>()
            .having((s) => s.connecting, 'connecting', false)
            .having((s) => s.models, 'models', hasLength(1))
            .having((s) => s.selectedModel, 'selectedModel', 'llama3.2:3b'),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'initialize_whenNoModelsInstalled_emitsErrorKind',
      build: () {
        fakeOllama.models = const [];
        return buildCubit();
      },
      act: (cubit) => cubit.initialize(),
      expect: () => [
        isA<WorkspaceReady>().having((s) => s.connecting, 'connecting', true),
        isA<WorkspaceReady>().having(
          (s) => s.errorKind,
          'errorKind',
          WorkspaceErrorKind.noModelsInstalled,
        ),
      ],
    );
  });

  group('WorkspaceCubit.selectRoot', () {
    blocTest<WorkspaceCubit, WorkspaceState>(
      'selectRoot_whenFolderDoesNotExist_emitsErrorWithoutPersisting',
      build: buildCubit,
      seed: () =>
          WorkspaceReady(host: Uri.parse('http://127.0.0.1:11434'), root: root),
      act: (cubit) => cubit.selectRoot('/caminho/inexistente/xyz'),
      expect: () => [
        isA<WorkspaceReady>().having(
          (s) => s.errorKind,
          'errorKind',
          WorkspaceErrorKind.folderNotFound,
        ),
      ],
      verify: (_) => expect(fakeStorage.saveCallCount, 0),
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'selectRoot_whenFolderExists_persistsActiveRootAndDedupesRecents',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        recentRoots: [root.path],
      ),
      act: (cubit) => cubit.selectRoot(otherRoot.path),
      verify: (_) {
        expect(fakeStorage.saveCallCount, greaterThan(0));
        expect(fakeStorage.lastSaved!.activeRoot, otherRoot.path);
        expect(fakeStorage.lastSaved!.recentRoots, [otherRoot.path, root.path]);
      },
    );
  });

  group('WorkspaceCubit.clearRoot', () {
    blocTest<WorkspaceCubit, WorkspaceState>(
      'clearRoot_removesRootAndPersistsNull',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        recentRoots: [root.path],
      ),
      act: (cubit) => cubit.clearRoot(),
      expect: () => [
        isA<WorkspaceReady>().having((s) => s.root, 'root', isNull),
      ],
      verify: (_) {
        expect(fakeStorage.saveCallCount, greaterThan(0));
        expect(fakeStorage.lastSaved!.activeRoot, isNull);
      },
    );
  });

  group('WorkspaceCubit.selectModel', () {
    blocTest<WorkspaceCubit, WorkspaceState>(
      'selectModel_onlySelectsWithoutLoadingModel',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        models: const [
          OllamaModelInfo(name: 'llama3.2:3b'),
          OllamaModelInfo(name: 'gemma2:2b'),
        ],
        selectedModel: 'llama3.2:3b',
      ),
      act: (cubit) => cubit.selectModel('gemma2:2b'),
      expect: () => [
        isA<WorkspaceReady>()
            .having((s) => s.selectedModel, 'selectedModel', 'gemma2:2b')
            .having(
              (s) => s.modelState,
              'modelState',
              WorkspaceModelState.stopped,
            ),
      ],
      verify: (_) {
        expect(fakeOllama.loadModelCallCount, 0);
        expect(fakeStorage.saveCallCount, greaterThan(0));
        expect(fakeStorage.lastSaved!.model, 'gemma2:2b');
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'selectModel_whenModelAlreadyRunning_derivesRunningState',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        models: const [
          OllamaModelInfo(name: 'llama3.2:3b'),
          OllamaModelInfo(name: 'gemma2:2b'),
        ],
        runningModels: const [
          OllamaRunningModel(name: 'gemma2:2b', isInstalled: true),
        ],
        selectedModel: 'llama3.2:3b',
      ),
      act: (cubit) => cubit.selectModel('gemma2:2b'),
      expect: () => [
        isA<WorkspaceReady>()
            .having((s) => s.selectedModel, 'selectedModel', 'gemma2:2b')
            .having(
              (s) => s.modelState,
              'modelState',
              WorkspaceModelState.running,
            ),
      ],
      verify: (_) => expect(fakeOllama.loadModelCallCount, 0),
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'selectModel_whenSameModel_doesNothing',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        models: const [OllamaModelInfo(name: 'llama3.2:3b')],
        selectedModel: 'llama3.2:3b',
      ),
      act: (cubit) => cubit.selectModel('llama3.2:3b'),
      expect: () => [],
      verify: (_) {
        expect(fakeOllama.loadModelCallCount, 0);
        expect(fakeStorage.saveCallCount, 0);
      },
    );
  });

  group('WorkspaceCubit.startModel/stopModel', () {
    blocTest<WorkspaceCubit, WorkspaceState>(
      'startModel_emitsStartingBeforeRunning',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        models: const [OllamaModelInfo(name: 'llama3.2:3b')],
        selectedModel: 'llama3.2:3b',
      ),
      act: (cubit) {
        // O fake nao simula loadModel afetando listRunningModels: refletimos
        // o efeito esperado do lado do servidor manualmente.
        fakeOllama.runningModels = const [
          OllamaRunningModel(name: 'llama3.2:3b', isInstalled: true),
        ];
        return cubit.startModel();
      },
      expect: () => [
        isA<WorkspaceReady>().having(
          (s) => s.modelState,
          'modelState',
          WorkspaceModelState.starting,
        ),
        isA<WorkspaceReady>().having(
          (s) => s.modelState,
          'modelState',
          WorkspaceModelState.running,
        ),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'stopModel_whenRepositoryFails_revertsToRunningInsteadOfClaimingStopped',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        models: const [OllamaModelInfo(name: 'llama3.2:3b')],
        runningModels: const [
          OllamaRunningModel(name: 'llama3.2:3b', isInstalled: true),
        ],
        selectedModel: 'llama3.2:3b',
        modelState: WorkspaceModelState.running,
      ),
      act: (cubit) {
        fakeOllama.failure = const OllamaServerException('falhou');
        return cubit.stopModel();
      },
      // O servidor nao confirmou o unload: o modelo continua carregado, entao
      // o estado deve refletir isso (porta `_updateModelState()` em
      // `desktop_controller.dart:365-369`), nao assumir "parado" as cegas.
      expect: () => [
        isA<WorkspaceReady>().having(
          (s) => s.modelState,
          'modelState',
          WorkspaceModelState.starting,
        ),
        isA<WorkspaceReady>()
            .having((s) => s.errorKind, 'errorKind', isNotNull)
            .having(
              (s) => s.modelState,
              'modelState',
              WorkspaceModelState.running,
            ),
      ],
    );
  });

  group('WorkspaceCubit.saveSettings', () {
    blocTest<WorkspaceCubit, WorkspaceState>(
      'saveSettings_whenHostChangedAndNoModels_failsWithoutPersisting',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        models: const [OllamaModelInfo(name: 'llama3.2:3b')],
        selectedModel: 'llama3.2:3b',
      ),
      act: (cubit) {
        fakeOllama.models = const [];
        return cubit.saveSettings(
          hostText: 'http://192.168.0.9:11434',
          temperature: 0.5,
          contextLength: null,
          keepAlive: null,
          timeout: null,
          allowEdit: true,
          allowCommands: true,
          contextFilesEnabled: true,
        );
      },
      expect: () => [
        isA<WorkspaceReady>().having(
          (s) => s.errorKind,
          'errorKind',
          WorkspaceErrorKind.saveSettingsFailed,
        ),
      ],
      verify: (_) => expect(fakeStorage.saveCallCount, 0),
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'saveSettings_whenHostUnchanged_persistsNewInferenceAndPermissions',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        models: const [OllamaModelInfo(name: 'llama3.2:3b')],
        selectedModel: 'llama3.2:3b',
      ),
      act: (cubit) => cubit.saveSettings(
        hostText: 'http://127.0.0.1:11434',
        temperature: 0.7,
        contextLength: 8192,
        keepAlive: const Duration(hours: 1),
        timeout: const Duration(seconds: 60),
        allowEdit: false,
        allowCommands: false,
        contextFilesEnabled: true,
      ),
      verify: (cubit) {
        expect(fakeStorage.saveCallCount, greaterThan(0));
        expect(fakeStorage.lastSaved!.inference.temperature, 0.7);
        expect(fakeStorage.lastSaved!.permissions.allowEdit, isFalse);
        expect(fakeStorage.lastSaved!.contextFilesEnabled, isTrue);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'saveSettings_persistsContextFilesEnabled',
      build: buildCubit,
      seed: () => WorkspaceReady(
        host: Uri.parse('http://127.0.0.1:11434'),
        root: root,
        models: const [OllamaModelInfo(name: 'llama3.2:3b')],
        selectedModel: 'llama3.2:3b',
      ),
      act: (cubit) => cubit.saveSettings(
        hostText: 'http://127.0.0.1:11434',
        temperature: 0.1,
        contextLength: null,
        keepAlive: null,
        timeout: null,
        allowEdit: true,
        allowCommands: true,
        contextFilesEnabled: false,
      ),
      verify: (_) =>
          expect(fakeStorage.lastSaved!.contextFilesEnabled, isFalse),
    );
  });
}
