import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/common/services/desktop_storage_service.dart';
import 'package:salvador_desktop/common/services/system_memory_service.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/desktop_preferences_entity.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';
import 'package:salvador_desktop/domain/interfaces/ollama_repository.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_state.dart';

class WorkspaceCubit extends Cubit<WorkspaceState> {
  WorkspaceCubit(
    this._ollamaRepository,
    this._storage, {
    Directory? initialRoot,
    Uri? initialHost,
    SystemMemoryReader? memoryReader,
  }) : _memoryReader = memoryReader ?? SystemMemoryReader(),
       super(
         WorkspaceReady(
           host: initialHost ?? Uri.parse('http://127.0.0.1:11434'),
           root: initialRoot?.absolute,
         ),
       );

  static const _defaultKeepAlive = Duration(minutes: 5);
  static const _maxRecentRoots = 8;

  final OllamaRepository _ollamaRepository;
  final DesktopStorageService _storage;
  final SystemMemoryReader _memoryReader;

  Future<void> initialize() async {
    final saved = await _storage.load();
    final current = state as WorkspaceReady;
    Directory? root;
    final savedRoot = saved.activeRoot;
    if (savedRoot != null && Directory(savedRoot).existsSync()) {
      root = Directory(savedRoot).absolute;
    }
    emit(
      WorkspaceReady(
        host: saved.host ?? current.host,
        root: root,
        connecting: true,
        selectedModel: saved.model,
        inference: saved.inference,
        permissions: saved.permissions,
        contextFilesEnabled: saved.contextFilesEnabled,
        recentRoots: saved.recentRoots,
        sessions: saved.sessions,
      ),
    );
    await _connect();
  }

  Future<void> selectRoot(String path) async {
    final current = state;
    if (current is! WorkspaceReady) return;
    final candidate = Directory(path).absolute;
    if (!candidate.existsSync()) {
      emit(
        current.copyWith(
          errorKind: WorkspaceErrorKind.folderNotFound,
          error: 'A pasta nao existe: ${candidate.path}',
        ),
      );
      return;
    }
    final recentRoots = [
      candidate.path,
      ...current.recentRoots.where((recent) => recent != candidate.path),
    ];
    emit(
      current.copyWith(
        root: candidate,
        recentRoots: recentRoots,
        clearError: true,
      ),
    );
    await _persist();
  }

  /// Desvincula o projeto atual: o chat continua liberado, so sem ferramentas
  /// de arquivo/comando (que dependem de uma raiz confinada).
  Future<void> clearRoot() async {
    final current = state;
    if (current is! WorkspaceReady) return;
    emit(current.copyWith(clearRoot: true, clearError: true));
    await _persist();
  }

  Future<void> selectModel(String? model) async {
    final current = state;
    if (current is! WorkspaceReady) return;
    if (model == null || model == current.selectedModel) return;
    // Selecionar nao inicia o modelo: o estado deriva dos modelos ja em
    // execucao; o start acontece so pelo botao ou ao enviar uma mensagem.
    final running = current.runningModels.any(
      (runningModel) => runningModel.name == model,
    );
    emit(
      current.copyWith(
        selectedModel: model,
        modelState: running
            ? WorkspaceModelState.running
            : WorkspaceModelState.stopped,
        clearError: true,
      ),
    );
    await _persist();
  }

  Future<void> startModel() async {
    final current = state;
    if (current is! WorkspaceReady) return;
    if (current.selectedModel == null ||
        current.modelState != WorkspaceModelState.stopped) {
      return;
    }
    emit(
      current.copyWith(
        modelState: WorkspaceModelState.starting,
        clearError: true,
      ),
    );
    final result = await _ollamaRepository.loadModel(
      host: current.host,
      model: current.selectedModel!,
      keepAlive: current.inference.keepAlive ?? _defaultKeepAlive,
    );
    switch (result) {
      case Error(:final error):
        emit(
          (state as WorkspaceReady).copyWith(
            modelState: WorkspaceModelState.stopped,
            errorKind: WorkspaceErrorKind.modelLoadFailed,
            error: error,
          ),
        );
      case Ok():
        await _refreshRunningModels();
    }
  }

  Future<void> stopModel() async {
    final current = state;
    if (current is! WorkspaceReady) return;
    if (current.selectedModel == null ||
        current.modelState != WorkspaceModelState.running) {
      return;
    }
    emit(
      current.copyWith(
        modelState: WorkspaceModelState.starting,
        clearError: true,
      ),
    );
    final result = await _ollamaRepository.unloadModel(
      host: current.host,
      model: current.selectedModel!,
    );
    switch (result) {
      case Error(:final error):
        // O servidor nao confirmou o unload: deriva o estado do ultimo
        // `runningModels` conhecido (ainda contem o modelo), em vez de
        // assumir "parado" as cegas.
        final ready = state as WorkspaceReady;
        final stillRunning = ready.runningModels.any(
          (running) => running.name == ready.selectedModel,
        );
        emit(
          ready.copyWith(
            modelState: stillRunning
                ? WorkspaceModelState.running
                : WorkspaceModelState.stopped,
            errorKind: WorkspaceErrorKind.modelLoadFailed,
            error: error,
          ),
        );
      case Ok():
        await _refreshRunningModels();
    }
  }

  Future<void> saveSettings({
    required String hostText,
    required double temperature,
    required int? contextLength,
    required Duration? keepAlive,
    required Duration? timeout,
    required bool allowEdit,
    required bool allowCommands,
    required bool contextFilesEnabled,
  }) async {
    final current = state;
    if (current is! WorkspaceReady) return;
    final parsedHost = Uri.tryParse(hostText.trim());
    if (parsedHost == null ||
        !parsedHost.hasScheme ||
        parsedHost.host.isEmpty) {
      emit(
        current.copyWith(
          errorKind: WorkspaceErrorKind.invalidHost,
          error: 'Informe uma URL válida para o Ollama.',
        ),
      );
      return;
    }

    final nextInference = InferenceOptions(
      temperature: temperature,
      contextLength: contextLength,
      keepAlive: keepAlive,
      timeout: timeout,
    );
    final nextPermissions = AgentPermissions(
      allowEdit: allowEdit,
      allowCommands: allowCommands,
    );
    final hostChanged = parsedHost != current.host;

    List<OllamaModelInfo> models = current.models;
    List<OllamaRunningModel> runningModels = current.runningModels;
    var selectedModel = current.selectedModel;

    if (hostChanged) {
      final modelsResult = await _ollamaRepository.listModels(host: parsedHost);
      switch (modelsResult) {
        case Error(:final error):
          emit(
            current.copyWith(
              errorKind: WorkspaceErrorKind.saveSettingsFailed,
              error: error,
            ),
          );
          return;
        case Ok(:final value):
          models = value;
      }
      final runningResult = await _ollamaRepository.listRunningModels(
        host: parsedHost,
        installed: models,
      );
      runningModels = runningResult.when(ok: (r) => r, error: (_) => const []);
      if (selectedModel == null ||
          !models.any((model) => model.name == selectedModel)) {
        selectedModel = models.first.name;
      }
    }

    emit(
      current.copyWith(
        host: parsedHost,
        models: models,
        runningModels: runningModels,
        selectedModel: selectedModel,
        inference: nextInference,
        permissions: nextPermissions,
        contextFilesEnabled: contextFilesEnabled,
        clearError: true,
      ),
    );
    await _persist();
    if (hostChanged) await _refreshRunningModels();
  }

  /// Chamado pela View quando `ChatCubit.newSession()` encerra a sessao
  /// atual e produz um resumo - `ChatCubit` conhece titulo/data/contagem de
  /// acoes, mas nao a persistencia, que fica no `WorkspaceCubit` junto do
  /// resto de `DesktopPreferencesEntity`.
  Future<void> recordSession(PersistedSessionSummaryEntity summary) async {
    final current = state;
    if (current is! WorkspaceReady) return;
    emit(current.copyWith(sessions: [summary, ...current.sessions]));
    await _persist();
  }

  Future<int?> availableMemory() => _memoryReader.availableBytes();

  Future<int?> fetchModelContext(String name) async {
    final current = state;
    if (current is! WorkspaceReady) return null;
    final result = await _ollamaRepository.showModelContext(
      host: current.host,
      model: name,
    );
    return result.when(ok: (context) => context, error: (_) => null);
  }

  /// Assume que o chamador ja deixou `state.connecting == true` antes de
  /// invocar - `initialize()` e o unico chamador hoje.
  Future<void> _connect() async {
    final current = state;
    if (current is! WorkspaceReady) return;

    final connectionResult = await _ollamaRepository.testConnection(
      host: current.host,
    );
    switch (connectionResult) {
      case Error(:final error):
        emit(
          (state as WorkspaceReady).copyWith(
            connecting: false,
            errorKind: WorkspaceErrorKind.connectionFailed,
            error: error,
          ),
        );
        return;
      case Ok():
        break;
    }

    final modelsResult = await _ollamaRepository.listModels(host: current.host);
    switch (modelsResult) {
      case Error(:final error):
        final kind = error is OllamaServerException
            ? WorkspaceErrorKind.noModelsInstalled
            : WorkspaceErrorKind.connectionFailed;
        emit(
          (state as WorkspaceReady).copyWith(
            connecting: false,
            errorKind: kind,
            error: error,
          ),
        );
        return;
      case Ok(:final value):
        final models = value;
        final currentModel = current.selectedModel;
        final selected =
            currentModel != null &&
                models.any((model) => model.name == currentModel)
            ? currentModel
            : models.first.name;

        final runningResult = await _ollamaRepository.listRunningModels(
          host: current.host,
          installed: models,
        );
        final running = runningResult.when(
          ok: (r) => r,
          error: (_) => const <OllamaRunningModel>[],
        );
        final modelState = running.any((model) => model.name == selected)
            ? WorkspaceModelState.running
            : WorkspaceModelState.stopped;

        emit(
          (state as WorkspaceReady).copyWith(
            connecting: false,
            models: models,
            runningModels: running,
            selectedModel: selected,
            modelState: modelState,
            clearError: true,
          ),
        );
        await _persist();
    }
  }

  Future<void> _refreshRunningModels() async {
    final current = state;
    if (current is! WorkspaceReady) return;
    final result = await _ollamaRepository.listRunningModels(
      host: current.host,
      installed: current.models,
    );
    final running = result.when(
      ok: (r) => r,
      error: (_) => current.runningModels,
    );
    final modelState =
        running.any((model) => model.name == current.selectedModel)
        ? WorkspaceModelState.running
        : WorkspaceModelState.stopped;
    emit(current.copyWith(runningModels: running, modelState: modelState));
  }

  Future<void> _persist() {
    final current = state as WorkspaceReady;
    return _storage.save(
      DesktopPreferencesEntity(
        host: current.host,
        model: current.selectedModel,
        inference: current.inference,
        permissions: current.permissions,
        contextFilesEnabled: current.contextFilesEnabled,
        activeRoot: current.root?.path,
        recentRoots: current.recentRoots.length > _maxRecentRoots
            ? current.recentRoots.sublist(0, _maxRecentRoots)
            : current.recentRoots,
        sessions: current.sessions,
      ),
    );
  }
}
